my %h=(a=>1); my $r=\%h; my $n = $h{a} + ($r->{a} = 7); print "$n\n";
