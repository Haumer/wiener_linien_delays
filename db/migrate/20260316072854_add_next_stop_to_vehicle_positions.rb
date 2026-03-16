class AddNextStopToVehiclePositions < ActiveRecord::Migration[7.1]
  def change
    add_column :vehicle_positions, :next_stop_name, :string
  end
end
