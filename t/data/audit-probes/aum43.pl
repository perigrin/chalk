my %h=(a=>1); my $f = sub { $h{b} = 2; 0 }; my @c = (%h, $f->()); print scalar(@c), "\n";
