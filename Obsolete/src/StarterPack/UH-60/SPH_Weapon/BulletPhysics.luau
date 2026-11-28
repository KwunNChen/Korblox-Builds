-- Settings for bullet ricochet and penetration

local module = {}

module.materialProperties = {
	Stone = {
		RicochetAngle = {70, 90}; -- Angle required to ricochet will be randomly chosen between these angles
		MinRicochetVelocity = 500; -- Minimum velocity required to ricochet off this material
		VelocityMultiplier = {50, 70}; -- Random decrease in velocity /100, lower number = lower velocity
		RicochetDeviation = 100; -- Randomly deviates velocity after ricochet, higher number = more deviation
		
		PenetrationDepth = {0.2, 0.3};
		PenetrationVelocityDecrease = {5, 15};
		PenetrationDeviation = 150;
	};
	Ground = {
		RicochetAngle = {100, 180};
		MinRicochetVelocity = 550;
		VelocityMultiplier = {40, 60};
		RicochetDeviation = 100;

		PenetrationDepth = {0.2, 0.3};
		PenetrationVelocityDecrease = {15, 35};
		PenetrationDeviation = 250;
	};
	Metal = {
		RicochetAngle = {50, 70};
		MinRicochetVelocity = 200;
		VelocityMultiplier = {70, 80};
		RicochetDeviation = 200;

		PenetrationDepth = {0.2, 0.3};
		PenetrationVelocityDecrease = {5, 15};
		PenetrationDeviation = 50;
	};
	Wood = {
		RicochetAngle = {70, 90};
		MinRicochetVelocity = 400;
		VelocityMultiplier = {40, 50};
		RicochetDeviation = 100;

		PenetrationDepth = {0.2, 0.5};
		PenetrationVelocityDecrease = {5, 15};
		PenetrationDeviation = 150;
	};
	Glass = {
		RicochetAngle = {100, 180};
		MinRicochetVelocity = 500;
		VelocityMultiplier = {70, 80};
		RicochetDeviation = 100;

		PenetrationDepth = {0, 0};
		PenetrationVelocityDecrease = {5, 15};
		PenetrationDeviation = 150;
	};
	Fabric = {
		RicochetAngle = {100, 180};
		MinRicochetVelocity = 550;
		VelocityMultiplier = {30, 40};
		RicochetDeviation = 100;

		PenetrationDepth = {0.2, 0.3};
		PenetrationVelocityDecrease = {15, 35};
		PenetrationDeviation = 250;
	};
	Water = {
		RicochetAngle = {180, 360};
		MinRicochetVelocity = 1000;
		VelocityMultiplier = {10, 30};
		RicochetDeviation = 100;

		PenetrationDepth = {1000, 1000};
		PenetrationVelocityDecrease = {15, 35};
		PenetrationDeviation = 250;
	};
}

module.armorPen = 6 -- Penetration in milimeters
module.armorDamage = 1 -- Damage dealt to armor integrity if penetrating

return module
