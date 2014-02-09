require 'nokogiri'
require 'stripe'
require 'oauth'
include OAuth::Helper
include EtradeHelper
include DwollaHelper

GIV_FEE_AMOUNT = App.giv["giv_fee_percentage"].to_f
GIV_GRANT_AMOUNT = App.giv["giv_grant_amount"]
SHARE_PRECISION = App.giv["share_precision"]
PIN_DWOLLA = App.dwolla["pin_account"]

module CalculationShare
  class Calculation

    class << self

      def compute_share_price
        stripe_balance = get_stripe_balance
        etrade_balance = get_etrade_balance
        givbalance = stripe_balance + etrade_balance
      
        date_yesterday = Date.yesterday.strftime('%Y%m%d')

        # shares added by donation
        shares_donated_yesterday = Donation.where("date_format(created_at, '%Y%m%d') = ?", date_yesterday).sum(:shares_added)

        # shares removed by grant
        shares_granted_yesterday = CharityGrant.where("status = ?", "sent").where("date_format(created_at, '%Y%m%d') = ?", date_yesterday).sum(:shares_subtracted)
        donors_shares_total_beginning = Share.order("created_At DESC").last.share_total_end.to_f rescue 0.0
        share_total_end = (BigDecimal("#{donors_shares_total_beginning}") + BigDecimal("#{shares_donated_yesterday}") - BigDecimal("#{shares_granted_yesterday}")).round(SHARE_PRECISION)

        # get donation share price
        # givbalance / total_donor_shares_all_time
        preliminary_share_price = (BigDecimal("#{givbalance}") / BigDecimal("#{share_total_end}")).to_f

        preliminary_share_price = 100000.0 unless preliminary_share_price.finite?
        if preliminary_share_price.to_f.nan?
          preliminary_share_price = 100000.0
        end

        donation_share_price = (preliminary_share_price * 10).ceil / 10.0
        grant_share_price = (preliminary_share_price * 10).floor / 10.0

        new_record_share = Share.new(
                                     :stripe_balance => stripe_balance,
                                     :etrade_balance => etrade_balance,
                                     :share_total_beginning => donors_shares_total_beginning,
                                     :shares_added_by_donation => shares_donated_yesterday,
                                     :shares_subtracted_by_grants => shares_granted_yesterday,
                                     :share_total_end => share_total_end,
                                     :donation_price => donation_share_price,
                                     :grant_price => grant_share_price
                                    )
        if new_record_share.save
          puts "Share Price has been updated"
          JobMailer.success_compute(App.giv["email_support"], "compute_share_price").deliver
        else
          puts "ERROR"
        end
      end

      def grant_step_1
        stripe_balance = get_stripe_balance
        etrade_balance = get_etrade_balance
        givbalance = stripe_balance + etrade_balance
        
        endowments = Endowment.all

        endowments.each do |endowment|

          endowment_share_balance = BigDecimal("#{endowment.donations.sum(:shares_added)}") - BigDecimal("#{endowment.donor_grants.sum(:shares_subtracted)}")
          endowment_grant_shares = (BigDecimal("#{endowment_share_balance}") * BigDecimal("#{GIV_GRANT_AMOUNT}")).round(SHARE_PRECISION)
          charity_grant_shares = (BigDecimal("#{endowment_grant_shares}") / BigDecimal("#{endowment.charities.count}")).round(SHARE_PRECISION)

          endowment_donors = endowment.donations
          charities = endowment.charities

          charities.each do |charity|
            if charity.active.eql?("true")
              endowment_donors.each do |endowment_donor|
                grant_record = DonorGrant.new(
                                        :donor_id => endowment_donor.donor.id,
                                        :endowment_id => endowment.id,
                                        :charity_id => charity.id,
                                        :date => Date.today,
                                        :shares_subtracted => charity_grant_shares,
                                        :status => 'pending'
                                        )
                grant_record.save
                JobMailer.success_compute(App.giv["email_support"], "grantcalculation_step1").deliver
              end # end .each do |donor|
            end # charity.status = active
          end # end charities.each do |charity|
        end # end endowments.each do |endowment|
        puts "Grant share has been updated"
      end

      def charity_ignores_grant
        charity_grants = CharityGrant.where("status = ?", "sent")

        charity_grants.each do |charity_grant|
          modify_date = (charity_grant.created_at + 60.days).to_date  
          if Date.today > modify_date
            charity_grant.update_attributes(:status => 'uncollected')
            puts "Charity grant : #{charity_grant.transaction_id} status is uncollected"
          end
        end # end each charity_grants
      end

      def cumulative_etrade_balance(account_id)
        Etrade.update_balance(account_id)
      end

    private

      def get_stripe_balance
        begin
          stripe_balance = Stripe::Balance.retrieve
          stripe_pending = (stripe_balance["pending"][0][:amount].to_f) / 100
          stripe_available = (stripe_balance["available"][0][:amount].to_f) / 100
          total_stripe = stripe_pending + stripe_available
          puts "Stripe Balance : #{total_stripe}"
          return total_stripe
        rescue Stripe::CardError => e
          body = e.json_body
          err  = body[:error]
          Rails.logger.debug "Status is: #{e.http_status}"
          Rails.logger.debug "Type is: #{err[:type]}"
          Rails.logger.debug "Code is: #{err[:code]}"
          Rails.logger.debug "Param is: #{err[:param]}"
          Rails.logger.debug "Message is: #{err[:message]}"
        end
      end

      def get_etrade_balance
        # just let return error message default from api
        etrade_balance = Etrade.get_net_account_value
        etrade_balance = BigDecimal(etrade_balance.to_s) - 1000
        puts "Etrade Balance : #{etrade_balance}"
        return etrade_balance
        
      end

    end # end self
  end
end
