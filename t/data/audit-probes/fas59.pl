our $x=1; sub n { local $x=7; rd() } sub rd { $x } my $v = $x . n() . $x; print "$v\n";
