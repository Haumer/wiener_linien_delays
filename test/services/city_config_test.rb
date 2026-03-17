require "test_helper"

class CityConfigTest < ActiveSupport::TestCase
  test "has 20 cities" do
    assert_equal 20, CityConfig.keys.size
  end

  test "each city has required fields" do
    CityConfig.all.each do |key, config|
      assert config[:name].present?, "#{key} missing name"
      assert config[:population].positive?, "#{key} missing population"
      assert config[:rect][:llCrd][:x].is_a?(Integer), "#{key} bad rect"
      assert config[:center].is_a?(Array), "#{key} missing center"
    end
  end

  test "find returns city by key" do
    assert_equal "Wien", CityConfig.find("wien")[:name]
    assert_nil CityConfig.find("nonexistent")
  end

  test "enabled reads from ENV" do
    ENV["TRANSIT_CITIES"] = "wien,graz"
    assert_equal %w[wien graz], CityConfig.enabled
  ensure
    ENV.delete("TRANSIT_CITIES")
  end

  test "enabled ignores unknown cities" do
    ENV["TRANSIT_CITIES"] = "wien,fake_city"
    assert_equal %w[wien], CityConfig.enabled
  ensure
    ENV.delete("TRANSIT_CITIES")
  end
end
