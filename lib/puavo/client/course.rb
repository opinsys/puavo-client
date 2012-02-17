module Puavo
  module Client

    # Course model include following attribute:
    # name (human readable name)
    # course_id (unique id)
    # description
    # puavo_id
    class Course < Model
      model_path :prefix => '/users', :path => "/courses"
    end
  end
end
