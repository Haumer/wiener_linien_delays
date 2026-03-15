require "test_helper"

class OebbVehicleServiceTest < ActiveSupport::TestCase
  test "maps supported products and includes next stop timing" do
    service = OebbVehicleService.new(client: fake_client(vehicle_response))

    result = service.call

    assert_equal 2, result[:vehicles].size
    assert_equal({ "tram" => 1, "bus" => 0, "sbahn" => 0, "obus" => 0, "rail" => 1 }, stringify_keys(result[:counts]))

    tram = result[:vehicles].first
    assert_equal "tram", tram[:category]
    assert_equal "Tram", tram[:category_label]
    assert_equal 2, tram[:next_stops].size
    assert_equal "Wien Oper", tram[:next_stops].first[:name]

    train = result[:vehicles].last
    assert_equal "rail", train[:category]
    assert_equal "Salzburg", train[:direction]
  end

  private

  def fake_client(response)
    Struct.new(:payload) do
      def call(*)
        payload
      end
    end.new(response)
  end

  def vehicle_response
    {
      "date" => "20260313",
      "time" => "194203",
      "common" => {
        "prodL" => [
          {
            "name" => "Tram 62",
            "prodCtx" => { "line" => "62", "catOutS" => "str", "catOutL" => "Strassenbahn" }
          },
          {
            "name" => "U4",
            "prodCtx" => { "line" => "U4", "catOutS" => "U", "catOutL" => "U-Bahn" }
          },
          {
            "name" => "RJ 546",
            "prodCtx" => { "line" => "RJ 546", "catOutS" => "RJ", "catOutL" => "Railjet" }
          }
        ],
        "locL" => [
          { "name" => "Wien Oper", "crd" => { "x" => 16_369_700, "y" => 48_200_400 } },
          { "name" => "Wien Meidling", "crd" => { "x" => 16_341_000, "y" => 48_181_000 } }
        ]
      },
      "jnyL" => [
        {
          "jid" => "tram-1",
          "prodX" => 0,
          "pos" => { "x" => 16_369_600, "y" => 48_200_100 },
          "dirTxt" => "Lainz",
          "proc" => 45,
          "date" => "20260313",
          "stopL" => [
            { "dTimeR" => "194500", "dTimeS" => "194500", "locX" => 0 },
            { "aTimeR" => "194900", "aTimeS" => "194800", "locX" => 1 }
          ]
        },
        {
          "jid" => "subway-1",
          "prodX" => 1,
          "pos" => { "x" => 16_340_000, "y" => 48_190_000 },
          "dirTxt" => "Hietzing",
          "proc" => 20,
          "date" => "20260313"
        },
        {
          "jid" => "train-1",
          "prodX" => 2,
          "pos" => { "x" => 16_375_000, "y" => 48_185_903 },
          "dirTxt" => "Salzburg",
          "proc" => 12,
          "date" => "20260313",
          "stopL" => []
        }
      ]
    }
  end

  def stringify_keys(hash)
    hash.transform_keys(&:to_s)
  end
end
