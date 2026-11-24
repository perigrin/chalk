my %h=(a=>1); my $t = %h && "yes"; my $u = scalar(%h) ? 1 : 0; print "$t$u\n";
