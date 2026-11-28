sub f { 1 } *g = \&f; print g(), "\n";
