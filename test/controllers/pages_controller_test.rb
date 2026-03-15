require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "home is publicly accessible" do
    get root_path

    assert_response :success
    assert_includes response.body, "Wien Live"
    assert_includes response.body, 'data-controller="live-map"'
  end
end
