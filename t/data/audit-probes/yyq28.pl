for my $s (qw(a1 b c3)) { $s =~ /(\d)/; print defined $1 ? $1 : "u" } print "\n";
