require "test_helper"

class OebbStopBoardServiceTest < ActiveSupport::TestCase
  test "builds live departure rows with minutes away" do
    service = OebbStopBoardService.new(client: fake_client(stop_board_response))

    result = service.call(lid: "A=1@O=Wien Hutteldorf Bahnhof@L=3@", name: "Wien Hutteldorf Bahnhof")

    assert_equal "Wien Hutteldorf Bahnhof", result[:stop][:name]
    assert_equal 2, result[:departures].size

    first_departure = result[:departures].first
    assert_equal "sbahn", first_departure[:category]
    assert_equal "Westbahnhof", first_departure[:destination]
    assert_equal "5", first_departure[:platform]

    second_departure = result[:departures].last
    assert_equal "rail", second_departure[:category]
    assert_equal "Salzburg", second_departure[:destination]
  end

  private

  def fake_client(response)
    Struct.new(:payload) do
      def call(*)
        payload
      end
    end.new(response)
  end

  def stop_board_response
    {
      "sD" => "20260313",
      "sT" => "194231",
      "common" => {
        "locL" => [
          { "name" => "Wien Hutteldorf Bahnhof" }
        ],
        "prodL" => [
          {
            "name" => "S 50",
            "prodCtx" => { "line" => "50", "catOutS" => "s", "catOutL" => "S-Bahn" }
          },
          {
            "name" => "WB 928",
            "prodCtx" => { "line" => "928", "catOutS" => "WB", "catOutL" => "WESTbahn" }
          }
        ]
      },
      "jnyL" => [
        {
          "date" => "20260313",
          "dirTxt" => "Westbahnhof",
          "stbStop" => {
            "dProdX" => 0,
            "dTimeR" => "194200",
            "dTimeS" => "194100",
            "dPltfS" => { "txt" => "5" }
          }
        },
        {
          "date" => "20260313",
          "dirTxt" => "Salzburg",
          "stbStop" => {
            "dProdX" => 1,
            "dTimeS" => "195500"
          }
        }
      ]
    }
  end
end
