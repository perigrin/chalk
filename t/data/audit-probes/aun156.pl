my %h=(a=>1); my $r = \%h; my $t = %$r ? "t" : "f"; %h = (); print $t, (%$r ? "t" : "f"), "\n";
