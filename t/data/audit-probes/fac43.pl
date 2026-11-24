my %h=(a=>1); my $r=\%h; my %c=%$r; $r->{a}=5; $c{z}=1; print "$c{a} ", exists $h{z}?1:0, "\n";
