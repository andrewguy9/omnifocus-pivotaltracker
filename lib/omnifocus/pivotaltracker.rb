require "open-uri"
require "json"
require "yaml"
require "cgi"
require 'time.rb'

module OmniFocus::Pivotaltracker
  PREFIX  = "PT"

  def load_or_create_config
    path   = File.expand_path "~/.omnifocus-pivotaltracker.yml"
    config = YAML.load(File.read(path)) rescue nil

    unless config then
      config = { :token => "TOKEN, get yours from https://www.pivotaltracker.com/profile", :user_name => "Full name, initials or unique part of the user's name" }

      File.open(path, "w") { |f|
        YAML.dump(config, f)
      }

      abort "Created default config in #{path}. Go fill it out."
    end

    # Make things working against single/multiple account settings.
    [config].flatten
  end

  def populate_pivotaltracker_tasks
    config    = load_or_create_config
    config.each do |conf|
      populate_pivotaltracker_tasks_for_project(conf[:token], conf[:user_name])
    end
  end

  def populate_pivotaltracker_tasks_for_project(token, user_name)
    projects = fetch_projects(token)

    projects.each do |project|
      dates = fetch_iterations(token, project["id"])
        .map{|iter| ticket_dates iter}
        .reduce({}) { |memo, obj| memo.merge obj}
      fetch_stories(token, project["id"], user_name).each do |story|
        defer, due = dates[story["id"]]
        process_story(project, story, defer, due)
      end
    end
  rescue OpenURI::HTTPError => error
    puts "Connection to Pivotal Tracker failed and updating could not be done."
  end

  def fetch_projects(token)
    url = "https://www.pivotaltracker.com/services/v5/projects"
    JSON.parse(open(url, "X-TrackerToken" => token).read)
  end

  def fetch_stories(token, project_id, user_name)
    url = "https://www.pivotaltracker.com/services/v5/projects/#{project_id}/stories?filter=" +
          "mywork:#{CGI.escape(user_name)}" +
          "%20state:unscheduled,planned,unstarted,started,rejected"

    JSON.parse(open(url, "X-TrackerToken" => token).read)
  end

  def fetch_iterations(token, project_id)
    url = "https://www.pivotaltracker.com/services/v5/projects/#{project_id}/iterations"

    JSON.parse(open(url, "X-TrackerToken" => token).read)
  end

  def ticket_dates(iteration)
    defer = Time.parse(iteration["start"])
    finish = Time.parse(iteration["finish"])
    keys = iteration["stories"].map{|story| [story["id"], [defer, finish]]}.flatten(1)
    Hash[*keys]
  end

  def process_story(project, story, defer, due)
    number       = story["id"]
    url          = story["url"]
    project_name = project["name"]
    ticket_id    = "#{PREFIX}-#{project_name}##{number}"
    title        = "#{ticket_id}: #{story["name"]}"

    if existing[ticket_id]
      bug_db[existing[ticket_id]][ticket_id] = true
      return
    end

    bug_db[project_name][ticket_id] = {:title=>title, :note=>url, :defer_date=>defer, :due_date=>due}
  end
end
