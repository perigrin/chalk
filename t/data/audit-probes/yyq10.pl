sub w { (caller(1))[3] } sub v { w() } print v(), "\n";
