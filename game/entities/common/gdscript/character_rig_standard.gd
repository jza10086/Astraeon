extends RefCounted
## Fixed 21-bone delivery contract; independent of installed character files.
const BONES: Dictionary[StringName, Dictionary] = {
	&"Root": {"parent": &"", "rest": Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)), Vector3(0, 0, 0))},
	&"Hips": {"parent": &"Root", "rest": Transform3D(Basis(Vector3(1, 0, -1.1920928e-07), Vector3(0, 0.99999994, 0), Vector3(1.1920928e-07, 0, 1)), Vector3(0, 0.6999999, 0))},
	&"LeftUpperLeg": {"parent": &"Hips", "rest": Transform3D(Basis(Vector3(-1, 0, -2.0663205e-07), Vector3(0, -1, 0), Vector3(-2.0663205e-07, 0, 1)), Vector3(0.0935, 0, 1.1146069e-08))},
	&"LeftLowerLeg": {"parent": &"LeftUpperLeg", "rest": Transform3D(Basis(Vector3(1, 0, -7.1054274e-15), Vector3(0, 1, 0), Vector3(7.1054274e-15, 0, 1)), Vector3(0, 0.26, 0))},
	&"RightUpperLeg": {"parent": &"Hips", "rest": Transform3D(Basis(Vector3(-1, 0, -2.0663205e-07), Vector3(0, -1, 0), Vector3(-2.0663205e-07, 0, 1)), Vector3(-0.0935, 0, -1.1146069e-08))},
	&"RightLowerLeg": {"parent": &"RightUpperLeg", "rest": Transform3D(Basis(Vector3(1, 0, -7.1054274e-15), Vector3(0, 1, 0), Vector3(7.1054274e-15, 0, 1)), Vector3(0, 0.26, 0))},
	&"Spine": {"parent": &"Hips", "rest": Transform3D(Basis(Vector3(1, 0, 1.1920928e-07), Vector3(0, 1, 0), Vector3(-1.1920928e-07, 0, 1)), Vector3(0, 0, 0))},
	&"Chest": {"parent": &"Spine", "rest": Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)), Vector3(0, 0.29000008, 0))},
	&"UpperChest": {"parent": &"Chest", "rest": Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)), Vector3(0, 0.20000005, 0))},
	&"LeftScapula": {"parent": &"UpperChest", "rest": Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)), Vector3(0.11, 0.08500004, -0.055))},
	&"LeftShoulder": {"parent": &"LeftScapula", "rest": Transform3D(Basis(Vector3(-0.19116986, -0.9133652, 0.3594693), Vector3(0.9787905, -0.20486355, -7.61915e-09), Vector3(0.073642164, 0.35184515, 0.9331569)), Vector3(-0.07, 0.05000007, 0.055))},
	&"LeftUpperArm": {"parent": &"LeftShoulder", "rest": Transform3D(Basis(Vector3(0.19116974, -0.9787906, -0.073642015), Vector3(0.9133653, 0.20486343, -0.35184523), Vector3(0.35946932, 9.7331615e-08, 0.9331569)), Vector3(7.0780516e-08, 0.21965884, -2.4214387e-08))},
	&"LeftLowerArm": {"parent": &"LeftUpperArm", "rest": Transform3D(Basis(Vector3(1, -1.303852e-08, -2.5878614e-07), Vector3(1.303852e-08, 1, -2.3451155e-15), Vector3(2.5878614e-07, -1.0290726e-15, 1)), Vector3(1.637265e-08, 0.24999996, -2.1518897e-15))},
	&"Grip_L": {"parent": &"LeftLowerArm", "rest": Transform3D(Basis(Vector3(-1, 5.1070268e-15, -8.742279e-08), Vector3(-5.1070268e-15, -1, -2.2323527e-22), Vector3(-8.742279e-08, 2.2323527e-22, 1)), Vector3(-6.9938224e-09, 0.27499992, 0.08))},
	&"Neck": {"parent": &"UpperChest", "rest": Transform3D(Basis(Vector3(1, -1.698995e-08, -1.1892956e-07), Vector3(0, 0.98994946, -0.14142145), Vector3(1.20137e-07, 0.14142145, 0.98994946)), Vector3(0, 0.17000008, -0.01))},
	&"Head": {"parent": &"Neck", "rest": Transform3D(Basis(Vector3(1, 0, 1.2013702e-07), Vector3(-1.6989953e-08, 0.98994946, 0.14142145), Vector3(-1.1892958e-07, -0.14142145, 0.98994946)), Vector3(-4.440892e-16, 0.07071061, 2.0489097e-08))},
	&"RightScapula": {"parent": &"UpperChest", "rest": Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)), Vector3(-0.11, 0.08500004, -0.055))},
	&"RightShoulder": {"parent": &"RightScapula", "rest": Transform3D(Basis(Vector3(-0.19116986, 0.9133652, -0.3594693), Vector3(-0.9787905, -0.20486355, -7.61915e-09), Vector3(-0.073642164, 0.35184515, 0.9331569)), Vector3(0.07, 0.05000007, 0.055))},
	&"RightUpperArm": {"parent": &"RightShoulder", "rest": Transform3D(Basis(Vector3(0.19116968, 0.9787906, 0.07364233), Vector3(-0.9133653, 0.20486349, -0.35184523), Vector3(-0.35946938, -2.0948735e-07, 0.9331569)), Vector3(-7.0780516e-08, 0.21965884, -2.4214387e-08))},
	&"RightLowerArm": {"parent": &"RightUpperArm", "rest": Transform3D(Basis(Vector3(1, -3.7252874e-09, -2.8858847e-07), Vector3(3.725296e-09, 1, 2.9802319e-08), Vector3(2.8858847e-07, -2.9802319e-08, 1)), Vector3(-3.8370565e-09, 0.24999996, 0))},
	&"Grip_R": {"parent": &"RightLowerArm", "rest": Transform3D(Basis(Vector3(-1, 3.3306733e-16, -8.742279e-08), Vector3(-3.3306733e-16, -1, -1.4558838e-23), Vector3(-8.742279e-08, 1.4558838e-23, 1)), Vector3(-6.9938224e-09, 0.27499992, 0.08))},
}
const TP_ROOT: Transform3D = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)), Vector3(0, 0, 0))
const FP_ROOT: Transform3D = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)), Vector3(0, -1.4, 0.06))
