our $x = 1; sub rd { $x } *x = \42; print rd(), "\n";
