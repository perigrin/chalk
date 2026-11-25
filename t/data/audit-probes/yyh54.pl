my $s = sub { (4,5,6) }->(); my @l = sub { (4,5,6) }->(); my $c = sub { my @a = (4,5,6); @a }->(); my $w = sub { wantarray }->(); print "$s@l$c", $w ? "L" : "S", "\n";
