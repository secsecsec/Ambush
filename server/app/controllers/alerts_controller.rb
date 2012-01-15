class AlertsController < ApplicationController
	protect_from_forgery
	before_filter :login_required, :except => :create

	# GET /signature_sets
	# GET /signature_sets.json
	def index
		if params[:time]
			@alerts = Alert.where('updated_at >= ?', Time.at(params[:time].to_f)).order('updated_at DESC')
		else
			@alerts = Alert.order('updated_at DESC')
		end

		respond_to do |format|
			format.html # index.html.erb
			format.json { 
				rows = ''
				remove = {}
				@alerts.each do |alert|
					rows << "<tr id=\"a#{alert.id}\" class=\"new\"><th scope=\"row\">#{alert.action.name }</th><td>#{alert.created_at } #{alert.updated_at if alert.count > 1 and alert.updated_at - alert.created_at > 5 }</td><td>#{alert.action.severity }</td><td>#{alert.action.actionStr }</td><td>#{alert.user }</td><td>#{alert.computer } (#{alert.ip })</td><td>#{alert.process } (#{alert.pid })</td><td>#{alert.action.available_function.available_dll.name }</td><td>#{alert.action.available_function.name+'('+alert.alert_args.map { |aa| aa.display }.join(",")+')' }</td><td>#{alert.count}</td></tr>"
					remove['a'+alert.id.to_s] = 1 if alert.created_at <= Time.at(params[:time].to_f)
				end
				render json: {:rows => rows, :lastUpdate => Time.now.to_f, :remove => remove } 
			}
		end
	end

	# GET /alerts/1
	# GET /alerts/1.json
	def show
		@alert = Alert.find(params[:id])

		respond_to do |format|
			format.html # show.html.erb
			format.json { render json: @alert }
		end
	end

	# GET /alerts/clear
	def clear
		Alert.destroy_all
		respond_to do |format|
				format.html { redirect_to '/alerts', notice: 'Alerts have been cleared.' }
				format.json { redirect_to '/alerts', notice: 'Alerts have been cleared.' }
		end
	end

	# POST /alerts
	# POST /alerts.json
	def create
		#put together alert
		@alert = Alert.new
		size = request.body.read(4).unpack('V')[0]
		message = request.body.read(size - 4)
		aid, @alert.pid, @alert.count, argcount = message.slice!(0, 16).unpack('VVVV')
		act = Action.find(aid)
		@alert.action = act
		@alert.ip = request.remote_ip
		@alert.save

		#save parameters
		act.available_function.parameters.all(:order => 'num').each do |param|
			aa = AlertArg.new(:alert => @alert)
			aa.parse(message, param)
			aa.save
		end

		#get info about user/computer/process
		userlen = message.slice!(0, 4).unpack('V')[0]
		@alert.user = message.slice!(0, userlen).force_encoding("UTF-16LE").encode('UTF-8')
		computerlen = message.slice!(0, 4).unpack('V')[0]
		@alert.computer = message.slice!(0, computerlen).force_encoding("UTF-16LE").encode('UTF-8')
		proclen = message.slice!(0, 4).unpack('V')[0]
		@alert.process = message.slice!(0, proclen).force_encoding("UTF-16LE").encode('UTF-8')

		#check for dups
		lastAlert = Alert.where(:pid => @alert.pid, :user => @alert.user, :action_id => aid, :ip => @alert.ip, 
				:computer => @alert.computer).where('created_at > ?', Time.current - 3600).first
		if lastAlert
			lastAlert.count += @alert.count
			lastAlert.save
			@alert.destroy
		else
			@alert.save
		end

		send_data ''
	end
end
