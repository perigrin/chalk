our $g=1; sub f { $g=5; 1 } my $v = ($g < f()) ? "lt" : "ge"; print "$v\n";
