class Api::EndowmentController < Api::BaseController

  skip_before_filter :require_authentication, :only => [:index, :show]

  def index
    page = params[:page] || 1
    perpage = params[:per_page] || 10
    query = params[:query] || ""

    endowments = []
    charities = []
    tags = Tag.find(:all, :conditions=> [ "name LIKE ?", "%#{query}%" ])
    tags.each do |tag|
      tag.charities.each do |c|
        charities << c
      end
    end

    charities.each do |c|
      endowments << c.endowments
    end

    Endowment.find(:all, :conditions=> [ "name LIKE ?", "%#{query}%" ]).each do |cg|
      endowments << cg
    end
    
    results = endowments.compact.flatten.uniq.paginate(:page => page, :per_page => perpage)
    respond_to do |format|
      if !results.empty?
        format.json { render json: results }
      else
        format.json { render json: { :message => "Not found" }.to_json }
      end
    end

  end

  def create
    group = Endowment.new_with_charities(params[:endowment])
    group.donor_id = current_session.session_id
    respond_to do |format|
      if group.save
        format.json { render json: group, status: :created }
      else
        format.json { render json: group.errors , status: :unprocessable_entity }
      end
    end
  end

  def show
    group = Endowment.find(params[:id])

    respond_to do |format|
      if group
        format.json { render json: group }
      else
        format.json { head :not_found }
      end
    end
  end

  def rename_endowment
    group = Endowment.find(params[:id])
    if (group.donor_id.to_s.eql?(current_session.session_id))
      respond_to do |format|
        if group.donations.size >= 1
          format.json { render json: "Cannot edit Charity Group when it already has donations to it" }
        else
          group.update_attributes(params[:endowment])
          format.json { render json: { :message => "Charity Group has been updated", :endowment => params[:endowment] }.to_json }
        end
      end
    else
      render json: { :message => "You cannot edit this charity group" }.to_json
    end
  end

  def add_charity
    group = Endowment.find(params[:id])
    
    if (group.donor_id.to_s.eql?(current_session.session_id))
      respond_to do |format|
        if group.donations.size < 1 
          group.add_charity(params[:charity_id])
          format.json { render json: { :message => "Charity has been added"}.to_json }
        else
          format.json { render json: "Cannot edit Charity Group when it already has donations to it" }
        end
      end #respond_to
    else
      render json: { :message => "You cannot edit this charity group" }.to_json
    end
  end

  def remove_charity
    group = Endowment.find(params[:id])
    if (group.donor_id.to_s.eql?(current_session.session_id))
      respond_to do |format|
        if group.donations.size < 1 
          group.remove_charity(params[:id], params[:charity_id])
          format.json { render json: { :message => "Charity has been removed" }.to_json }
        else
          format.json { render json: "Cannot edit Charity Group when it already has donations to it" }
        end
      end #respond_to
    else
      render json: { :message => "You can edit this charity group" }.to_json
    end
  end

  def destroy
    group = Endowment.find(params[:id])
    if (group.donor_id.to_s.eql?(current_session.session_id))
      respond_to do |format|
        if group.donations.size < 1
          group.delete(params[:charity])
          format.json { render json: "Destroyed #{params[:charity]} record." }
        else
          format.json { render json: "Cannot edit Charity Group when it already has donations to it" }
        end
      end
    else
      render json: { :message => "You can edit this charity group" }.to_json
    end
  end 

  def share_balance_information
    endowment = Endowment.find(params[:id])
    last_donation_price = Share.last.donation_price
    share_balance = endowment.donations.sum(:shares_added) - endowment.charity_grants.sum(:shares_subtracted) 
    endowment_balance = ((share_balance * last_donation_price) * 10).ceil / 10.0
    my_endowment_share_balance = current_donor.donations.where("endowment_id = ?", endowment.id).sum(:shares_added) - current_donor.charity_grants.where("endowment_id = ?", endowment.id).sum(:shares_subtracted)
    my_endowment_balance = ((my_endowment_share_balance * last_donation_price) * 10).ceil / 10.0
    render json: {:endowment_id => endowment.id, :endowment_balance => endowment_balance, :my_endowment_balance => my_endowment_balance}.to_json
  end

end