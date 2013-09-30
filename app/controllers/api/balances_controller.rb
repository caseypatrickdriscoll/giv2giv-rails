class Api::BalancesController < Api::BaseController
  before_filter :require_authentication

  def show_shares
    charity_group_id = params[:id]
  	givshares = current_donor.givshare.group(:donation_id).all(conditions: "charity_group_id = '#{charity_group_id}'")
    shares = []
    givshares.each do |givshare|
      last_donation = Givshare.where(donation_id: givshare.donation_id).last
      shares << last_donation
    end

    respond_to do |format|
      format.json { render json: shares }
    end
  end

  def share_charity_group
    charity_group_id = params[:id]
    givshares = Givshare.group(:donation_id).all(conditions: "charity_group_id = '#{charity_group_id}'")
    shares = []
    givshares.each do |givshare|
      last_donation = Givshare.where(donation_id: givshare.donation_id).last
      shares << last_donation
    end

    shares_data = {}
    shares.each do |share|
      pershare = (share.shares_bought_through_donations * share.donation_price).round(2)
      temp_share = {share.donor_id => {"donor_id" => share.donor_id, "donation_id" => share.donation_id, "pershare" => pershare }}
      shares_data.merge!(temp_share)
    end

    respond_to do |format|
      format.json { render json: shares_data }
    end
  end

end