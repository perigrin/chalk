my %h=(a=>1); my $add=sub { $h{$_[0]}=1 }; my $t=0; for my $k (qw(b c)) { $t+=keys %h; $add->($k) } print "$t\n";
