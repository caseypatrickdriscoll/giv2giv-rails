class PaymentAccount < ActiveRecord::Base
  require "stripe"

  VALID_PROCESSORS = %w(stripe)
  PLAN_ID = 1
  PER_SHARE_DEFAULT = 100000
  SHARE_TOTAL_DEFAULT = 0
  SHARE_PRECISION = App.giv["share_precision"]

  belongs_to :donor
  has_many :donations
  has_many :donor_subscriptions

  validates :requires_reauth, :inclusion => { :in => [false] }
  validates :processor, :presence => true, :inclusion => { :in => VALID_PROCESSORS }
  validates :donor, :presence => true
  before_validation :set_requires_reauth, :on => :create
  before_validation :downcase_processor, :on => :create

  class << self
    def new_account(stripeToken, donor_id, options = {})
      check_donor = Donor.find(donor_id)
      customer = Stripe::Customer.create(description: "Giv2Giv Subscription", email: check_donor.email, card: stripeToken)
      payment = PaymentAccount.new(options)
      payment.stripe_cust_id = customer.id
      if payment.save
        payment
      else
        payment.errors
      end
    end

    def one_time_payment(amount, endowment_id, email = nil, stripeToken = nil, payment_account_id = nil, password = nil)
      raise EndowmentInvalid unless (endowment = Endowment.find(endowment_id))

      num_of_charity = endowment.charities.count
      check_donor = Donor.find_by_email(email)
      amount = amount.to_i

      if (endowment.visibility.eql?("private")) and (check_donor.id != endowment.donor_id)
        { :message => "Sorry! You cannot make a donation to a private endowment" }.to_json
      else

        if num_of_charity > 0
          if amount < endowment.minimum_donation_amount.to_i
            { :message => "Minimum amount for create donation $#{endowment.minimum_donation_amount}" }.to_json
          else
            random_password = SecureRandom.hex(10)
            random_name = SecureRandom.hex(10)

            if check_donor.blank?
              # entry as unregistered donor
              email = random_name + "@" + random_password + ".com"

              begin
                customer = Stripe::Customer.create(description: "Giv2Giv Donation", email: email, card: stripeToken)
              rescue Stripe::CardError => e
                body = e.json_body
                err  = body[:error]
                { :message => "#{err[:message]}" }.to_json
                return false
              end

              donor = Donor.new(
                                 :name => random_name,
                                 :email => email,
                                 :password => random_password,
                                 :type_donor => 'unregistered'
                               )

              if donor.save
                  # create new payment
                  payment = PaymentAccount.new(
                                               :processor => "stripe",
                                               :donor_id => donor.id,
                                               :requires_reauth => 0,
                                               :stripe_cust_id => customer.id
                                              )
                  if payment.save

                    begin
                      cust_charge = Stripe::Charge.create(
                                                          :amount => amount,
                                                          :currency => "usd",
                                                          :description => "giv2giv.org donation to #{Endowment.find(endowment_id).name}",
                                                          :customer => payment.stripe_cust_id,
                                                         )
                      subscription = donor.donor_subscriptions.build(:donor_id => donor.id,
                                                                  :payment_account_id => payment.id,
                                                                  :endowment_id => endowment_id,
                                                                  :stripe_subscription_id => cust_charge.id,
                                                                  :type_subscription => "one_time_payment",
                                                                  :gross_amount => amount
                                                                  )
                      rescue Stripe::CardError => e
                        body = e.json_body
                        err  = body[:error]
                        { :message => "#{err[:message]}" }.to_json
                      return false
                    end

                    if subscription.defined? && subscription.save
                      { :message => "Success" }.to_json
                    else
                      { :message => "Error" }.to_json
                    end
                  else
                    payment.errors
                  end # end payment save
                else
                  { :message => "Error! Creating payment account" }.to_json
                end # end donor save

            else

              if check_donor.type_donor.eql?("unregistered")
                begin
                  cu = Stripe::Customer.retrieve(check_donor.payment_accounts.last.stripe_cust_id)
                  cu.card = stripeToken
                  cu.save
                  cust_charge = Stripe::Charge.create(
                                            :amount => amount,
                                            :currency => "usd",
                                            :description => "giv2giv.org donation to #{Endowment.find(endowment_id).name}",
                                            :customer => check_donor.payment_accounts.last.stripe_cust_id
                                           )

                  subscription = donor.donor_subscriptions.build(:donor_id => donor.id,
                                                               :payment_account_id => check_donor.payment_accounts.last.id,
                                                               :endowment_id => endowment_id,
                                                               :stripe_subscription_id => cust_charge.id,
                                                               :type_subscription => "one_time_payment",
                                                               :gross_amount => amount
                                                               )
                  rescue Stripe::CardError => e
                    body = e.json_body
                    err  = body[:error]
                    { :message => "#{err[:message]}" }.to_json
                    return false
                  end

                if subscription.save
                  { :message => "Success" }.to_json
                else
                  { :message => "Error" }.to_json
                end
              else
                check_donor = Donor.where("email = ? AND password = ? AND type_donor = 'registered'", email, password).first
                cust_id = check_donor.payment_accounts.find(payment_account_id)

                begin
                  cu = Stripe::Customer.retrieve(cust_id.stripe_cust_id)
                  cust_charge = Stripe::Charge.create(
                                                    :amount => amount,
                                                    :currency => "usd",
                                                    :description => "giv2giv.org donation to #{Endowment.find(endowment_id).name}",
                                                    :customer => cust_id.stripe_cust_id
                                                   )

                  subscription = check_donor.donor_subscriptions.build(:donor_id => check_donor.id,
                                                               :payment_account_id => cust_id.id,
                                                               :endowment_id => endowment_id,
                                                               :stripe_subscription_id => cust_charge.id,
                                                               :type_subscription => "one_time_payment",
                                                               :gross_amount => amount
                                                               )
                  rescue Stripe::CardError => e
                    body = e.json_body
                    err  = body[:error]
                    { :message => "#{err[:message]}" }.to_json
                    return false
                  end

                if subscription.defined? && subscription.save
                  { :message => "Success" }.to_json
                else
                  { :message => "Error" }.to_json
                end

              end # end check registered email
            end #end check email
          end # end check minimum donation
        else
          { :message => "You need add one or more charity to this group" }.to_json
        end # end check charity
      end # end check visibility

    end

    def update_account(stripeToken, donor_id, payment_id, options = {})
      check_donor = Donor.find(donor_id)
      customer = Stripe::Customer.retrieve(check_donor.payment_accounts.find(payment_id).stripe_cust_id)
      customer.card = stripeToken
      customer.save
    end

    def cancel_subscription(subscription_id)
      begin
        subscription = DonorSubscription.find(subscription_id)
        cust_id = PaymentAccount.find(subscription.payment_account_id).stripe_cust_id

        begin
          cu = Stripe::Customer.retrieve(cust_id)
          cu.subscriptions.retrieve(subscription.stripe_subscription_id).delete()
          subscription.destroy
          { :message => "Your subscription has been canceled" }.to_json

        rescue Stripe::Error => e
            body = e.json_body
            err = body[:error]
            { :message => "#{err[:message]}" }.to_json
            return false
        end

      rescue
        { :message => "Failed! Subscription or payment account not found" }.to_json
      end
    end

    def cancel_all_subscription(current_donor)
      begin
        payment_accounts = current_donor.payment_accounts
        payment_accounts.each do |payment_account|

        begin
          cu = Stripe::Customer.retrieve(payment_account.stripe_cust_id)
          cu.cancel_subscription
          payment_account.donor_subscriptions.destroy_all
        rescue Stripe::CardError => e
          body = e.json_body
          err  = body[:error]
          { :message => "#{err[:message]}" }.to_json
          return false
        end

        end # end each
        { :message => "Your subscriptions has been canceled" }.to_json
      rescue
        { :message => "Failed! No active subscription" }.to_json
      end
    end

  end # end self


  def donate_subscription(amount, endowment_id, payment_id, email)

    raise PaymentAccountInvalid unless self.valid?
    raise EndowmentInvalid unless Endowment.find_by_id(endowment_id)

    payment_donor = PaymentAccount.find_by_id(payment_id)
    endowment = Endowment.find_by_id(endowment_id)
    num_of_charity = endowment.charities.count
    check_donor = Donor.find(payment_donor.donor_id)
    amount = amount.to_i
    Rails.logger.debug amount

    if endowment.visibility.eql?("private") && payment_donor.donor_id != endowment.donor_id
      return { :message => "Sorry! You cannot make a donation to a private endowment" }.to_json
    end

    if num_of_charity < 1
      return { :message => "No charities in this endowment" }.to_json
    end

    if amount < endowment.minimum_donation_amount.to_i
      return { :message => "Minimum amount for create donation $#{endowment.minimum_donation_amount}" }.to_json
    end

    if !check_donor
      return { :message => "Wrong donor id" }.to_json
    end

    begin
      customer = Stripe::Customer.retrieve(check_donor.payment_accounts.find(payment_id).stripe_cust_id)

      id_subscription = customer.subscriptions.create(:plan => PLAN_ID, :quantity => amount, :prorate => false)

      subscription = donor.donor_subscriptions.build(:donor_id => donor.id,
                                             :payment_account_id => payment_id,
                                             :endowment_id => endowment_id,
                                             :stripe_subscription_id => id_subscription.id,
                                             :type_subscription => "per-month",
                                             :gross_amount => amount
                                             )

    rescue Stripe::CardError => e
      body = e.json_body
      err  = body[:error]
      { :message => "#{err[:message]}" }.to_json
      return false
    end

    if subscription.save
      { :message => "Success" }.to_json
    else
      { :message => "Error" }.to_json
    end # end subscription.save

  end # end donate_subscription


private

  def set_requires_reauth
    self.requires_reauth = false if !self.requires_reauth
    true
  end

  def downcase_processor
    self.processor = self.processor.downcase if self.processor
    true
  end
end
