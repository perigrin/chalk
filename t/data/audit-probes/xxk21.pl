my @a = ("ab","cd"); my $n = 0; $n += tr/a-c/A-C/ for @a; print "$n@a\n";
