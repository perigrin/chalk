our $x = "a"; sub c { $x = "bb"; 2 } my $r = \$x; print $$r . c(), "\n";
