sub f { "f1" } BEGIN { *g = \&f } print g(), "\n";
