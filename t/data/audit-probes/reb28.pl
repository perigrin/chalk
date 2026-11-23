our $g=1; sub f { local $g=2; 1 } sub k { f() ; $g } print k(), "\n";
