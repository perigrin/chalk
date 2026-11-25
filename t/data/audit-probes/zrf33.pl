my %h=(a=>1); my $r=\%h; $h{b}=2; my $n=keys %$r; $r->{c}=3; print $n, scalar(keys %h), "\n";
