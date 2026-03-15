require "test_helper"

class OebbStopServiceTest < ActiveSupport::TestCase
  test "filters unsupported stop products and keeps category metadata" do
    service = OebbStopService.new(client: fake_client(stop_response))

    Rails.cache.clear
    result = service.call

    assert_equal 2, result[:count]

    stop_names = result[:stops].map { |stop| stop[:name] }
    assert_includes stop_names, "Wien Hietzing"
    assert_includes stop_names, "Wien Hutteldorf Bahnhof"
    assert_not_includes stop_names, "Wien Hietzing (U4)"

    train_hub = result[:stops].find { |stop| stop[:name] == "Wien Hutteldorf Bahnhof" }
    assert_equal "sbahn", train_hub[:primary_category]
    assert_includes train_hub[:categories].map { |category| category[:key] }, "bus"
  end

  private

  def fake_client(response)
    Struct.new(:payload) do
      def call(*)
        payload
      end
    end.new(response)
  end

  def stop_response
    {
      "common" => {
        "prodL" => [
          {
            "name" => "Bus 13A",
            "prodCtx" => { "line" => "13A", "catOutS" => "Bus", "catOutL" => "Bus" }
          },
          {
            "name" => "U4",
            "prodCtx" => { "line" => "U4", "catOutS" => "U", "catOutL" => "U-Bahn" }
          },
          {
            "name" => "S 50",
            "prodCtx" => { "line" => "50", "catOutS" => "s", "catOutL" => "S-Bahn" }
          }
        ],
        "locL" => [
          {
            "extId" => "1",
            "name" => "Wien Hietzing",
            "lid" => "A=1@O=Wien Hietzing@L=1@",
            "crd" => { "x" => 16_304_868, "y" => 48_187_548 },
            "pRefL" => [0]
          },
          {
            "extId" => "2",
            "name" => "Wien Hietzing (U4)",
            "lid" => "A=1@O=Wien Hietzing (U4)@L=2@",
            "crd" => { "x" => 16_304_868, "y" => 48_187_548 },
            "pRefL" => [1]
          },
          {
            "extId" => "3",
            "name" => "Wien Hutteldorf Bahnhof",
            "lid" => "A=1@O=Wien Hutteldorf Bahnhof@L=3@",
            "crd" => { "x" => 16_261_118, "y" => 48_197_355 },
            "pRefL" => [0, 2]
          }
        ]
      }
    }
  end
end
