use feature "try"; no warnings; our $g=0; sub f { try { return 5 } catch ($e) { } finally { $g=1 } } my $v=f(); print "$v $g\n";
