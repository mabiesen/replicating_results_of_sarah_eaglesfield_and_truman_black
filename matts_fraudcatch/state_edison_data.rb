require 'json'
require 'date'

class StateEdisonData
  attr_reader :state_json_data, :state_name
  attr_reader :total_vote_count_drop, :biden_total_drop, :trump_total_drop
  attr_reader :winner
  attr_reader :current_total_votes
  attr_reader :current_percent_for_trump
  attr_reader :current_percent_for_biden

  PRINTING_SPACER = '------------------------------------------'
  
  def initialize(filepath)
    @state_name = File.basename(filepath, '.*').upcase
    state_json_data(filepath)
    total_vote_count_drop
    @biden_total_drop = vote_drop_total_for_candidate('Biden')
    @trump_total_drop = vote_drop_total_for_candidate('Trump')
  end

  def did_total_vote_count_drop?
    return true if @total_vote_count_drop < 0

    false
  end

  def did_biden_vote_count_drop?
    return true if @biden_total_drop < 0

    false
  end

  def did_trump_vote_count_drop?
    return true if @trump_total_drop < 0

    false
  end

  def biden_drop_more_than_trump?
    return true if @biden_total_drop < @trump_total_drop

    false
  end

  def state_json_data(filepath)
    return @state_json_data unless @state_json_data.nil? 

    json_data = JSON.parse(File.read(filepath))
    @state_json_data = convert_time_series_timestamp_to_datetime(json_data)
  end

  def time_series_data
    @state_json_data["data"]["races"][0]["timeseries"]
  end

  def winner
    return @winner unless @winner.nil?

    last_entry = time_series_data.last
    @winner = last_entry['vote_shares']['trumpd'] > last_entry['vote_shares']['bidenj'] ? 'trump' : 'biden'
  end

  def current_total_votes
    @current_total_votes || time_series_data.last['votes']
  end

  def current_percent_for_trump
    @current_percent_for_trump ||= time_series_data.last['vote_share']['trumpd'] 
  end

  def current_percent_for_biden
    @current_percent_for_biden ||= time_series_data.last['vote_share']['bidenj']
  end
  
  def comparative_time_series
    ret_array = []
    time_series_data.each_with_index do |tsdata, index|
      next if index == 0

      hsh = {}
      last_tsdata = time_series_data[index - 1]
      trump_key = 'trumpd'
      biden_key = 'bidenj'
      current_lead = tsdata['vote_shares'][trump_key] > tsdata['vote_shares'][biden_key] ? 'Trump' : 'Biden'
      last_lead = last_tsdata['vote_shares'][trump_key] > last_tsdata['vote_shares'][biden_key] ? 'Trump' : 'Biden'
      current_votes = tsdata['votes']
      last_votes = last_tsdata['votes']
      amount_dropped = (current_votes - last_votes) > 0 ? 0 : (current_votes - last_votes)

      hsh['lead_switched'] = current_lead == last_lead ? nil : current_lead 
      hsh['amount_dropped'] = amount_dropped
      hsh['previous_data'] = last_tsdata
      hsh['current_data'] = tsdata
      hsh['trump_drop'] = candidate_vote_drop_across_timeseries('trump', tsdata, last_tsdata)
      hsh['biden_drop'] = candidate_vote_drop_across_timeseries('biden', tsdata, last_tsdata)
      ret_array.push(hsh)
    end
    ret_array
  end

  # we are only looking at those instances where total amount dropped for now
  # will need to account for poor percentage granularity
  # will also need to look at those times that the total did not drop
  def vote_drop_total_for_candidate(candidate)
    candidate_key = candidate.downcase == 'trump' ? 'trump_drop' : 'biden_drop'

    times_total_vote_count_dropped.sum{|hsh| hsh[candidate_key]}
  end

  def total_vote_count_drop
    return @total_vote_count_drop unless @total_vote_count_drop.nil?

    comparative_time_series.sum{|hsh| hsh['amount_dropped']}
  end

  def times_total_vote_count_dropped
    comparative_time_series.select{|hsh| hsh['amount_dropped'] != 0}
  end

  def times_lead_switched
    comparative_time_series.select{|hsh| hsh['lead_switched'] != nil}
  end

  def print_report()
    puts "EVALUATING #{@state_name}"
    puts ""

    print_times_where_lead_switched
    print_times_where_total_vote_count_dropped
    print_times_where_candidate_total_dropped('Trump')
    print_times_where_candidate_total_dropped('Biden')
  end

  def print_times_where_total_vote_count_dropped
    puts PRINTING_SPACER
    puts "PRINTING TIMES TOTAL COUNT DROPPED IN #{@state_name}"
    puts PRINTING_SPACER
    data_array = comparative_time_series
    times_total_vote_count_dropped.each do |hsh|
      lead_no_switch_statement = "The lead did not switch"
      lead_switch_statement = "The lead switched in #{hsh['lead_switched']}'s favor"
      puts "total count dropped by #{hsh['amount_dropped']}\n"\
           "between #{hsh['previous_data']['timestamp']} "\
           "and #{hsh['current_data']['timestamp']}\n"\
           "#{hsh['lead_switched'].nil? ? lead_no_switch_statement : lead_switch_statement}\n\n"
           
    end
    puts "TOTAL DROP FOR STATE WAS #{data_array.sum{|hsh| hsh['amount_dropped']}}"
    puts PRINTING_SPACER
    puts "\n\n"
  end

  def print_times_where_lead_switched
    puts PRINTING_SPACER
    puts "PRINTING TIMES LEAD SWITCHED IN #{@state_name}"
    puts PRINTING_SPACER
    data_array = comparative_time_series
    times_lead_switched.each do |hsh|
      total_counts_dropped_statement = hsh['amount_dropped'].nil? ? 'did not drop' : "dropped by #{hsh['amount_dropped']}"
      lead_switch_statement = "The lead switched in #{hsh['lead_switched']}'s favor"
      puts "#{lead_switch_statement} at #{hsh['current_data']['timestamp']}\n"\
           "Total vote counts #{total_counts_dropped_statement}\n\n"

    end
    puts "TOTAL DROP FOR STATE WAS #{data_array.sum{|hsh| hsh['amount_dropped']}}"
    puts PRINTING_SPACER
    puts "\n\n"
  end

  def print_times_where_candidate_total_dropped(candidate)
    puts PRINTING_SPACER
    puts "PRINTING TIMES #{candidate}'s TOTAL DROPPED IN #{@state_name}"
    puts PRINTING_SPACER

    total_drop = 0
    candidate_key = candidate.downcase == 'trump' ? 'trumpd' : 'bidenj' 

    comparative_time_series.each do |hsh|
      tsdata = hsh['current_data']
      last_tsdata  = hsh['previous_data']
      last_total = last_tsdata['vote_shares'][candidate_key] * last_tsdata['votes']
      current_total =  tsdata['vote_shares'][candidate_key] * tsdata['votes']
      
      lead_no_switch_statement = "The lead did not switch"
      lead_switch_statement = "The lead switched in #{hsh['lead_switched']}'s favor"
      if last_total > current_total
        puts "AT #{tsdata['timestamp']}, #{candidate}'s total dropped by #{current_total - last_total}\n"\
             "Total drop for timeframe was #{hsh['amount_dropped']}\n"\
             "#{hsh['lead_switched'].nil? ? lead_no_switch_statement : lead_switch_statement}\n\n"
        total_drop += current_total - last_total
      end
    end
    puts "TOTAL DROP FOR #{candidate.upcase} was #{total_drop}"
    puts PRINTING_SPACER
    puts "\n\n"
  end

  private

  def candidate_vote_drop_across_timeseries(candidate, current_tsdata, last_tsdata)
    candidate_key = candidate.downcase == 'trump' ? 'trumpd' : 'bidenj'
    last_total = last_tsdata['vote_shares'][candidate_key] * last_tsdata['votes']
    current_total =  current_tsdata['vote_shares'][candidate_key] * current_tsdata['votes'] 
    current_total - last_total
  end

  def convert_time_series_timestamp_to_datetime(json_data)
    timeseries_data = json_data["data"]["races"][0]["timeseries"]
    date_and_time = '%Y-%m-%dT%H:%M:%S'
    new_timeseries = timeseries_data.map do |tsdata|
                       tsdata['timestamp'] = DateTime.strptime(tsdata['timestamp'], date_and_time)
                       tsdata
                     end
    new_timeseries = new_timeseries.sort_by do |tsdata|
                       tsdata['timestamp']
                     end
    json_data["data"]["races"][0]["timeseries"] = new_timeseries
    json_data
  end
end

