module Hpr
  struct UpdateRepositoryWorker
    include Worker::Base

    def perform(name : String)
      # Skip when repository id not exists (may be deleted).
      unless Git::Repo.repository_path?(name)
        error "repository folder not exists ... #{name}"
        return
      end

      # Skip when repository not exists at gitlab service(deleted remotely)
      unless project = search_project(name)
        error "repository of gitlab not exists ... #{name}"
        return
      end

      with_syncing(project, name) do
        repo = Git::Repo.repository(name)

        info "updating from origin ... #{name}"
        repo.set_config("hpr.status", "fetching")
        repo.fetch_remote("origin")

        info "pushing to gitlab ... #{name}"
        repo.set_config("hpr.status", "pushing")
        repo.push_remote("hpr")
        repo.set_config("hpr.updated", Utils.current_datetime)
        repo.set_config("hpr.status", "idle")
      end

      update_schedule(name)
    end

    private def with_syncing(project, name)
      description = project["description"].to_s
      if description.empty?
        repo_info = Utils.repository_info(name)
        description = "Mirror of #{repo_info["url"]}"
      end
      update_project_description(project, "[Syncing] #{description}")

      yield

      update_project_description(project, description)
    end

    private def update_project_description(project, description)
      Hpr.gitlab.edit_project(project["id"].as_i, {"description" => description})
    end

    private def search_project(name) : JSON::Any?
      projects = Hpr.gitlab.projects({"search" => name})
      selected = projects.as_a.select { |p| p["name"] == name }
      return if selected.empty?

      selected.first
    end
  end
end
