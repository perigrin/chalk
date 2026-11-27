my $x = 5; undef $x; my @a = (1); undef @a; my %h = (a=>1); undef %h; print defined $x ? "d" : "u", scalar(@a), scalar(keys %h), "\n";
