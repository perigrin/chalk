my %h=(k=>1); my $r=\%h; my $x=$h{k}; $r->{k}=2; my $y=$h{k}; $h{k}=3; my $z=$r->{k}; print "$x$y$z\n";
