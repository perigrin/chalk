my $f = sub { $main::g += 10 }; my $run = sub { $main::g = 0; for my $i (1..3) { $main::g = $main::g + 1; $f->(); } }; $run->(); print "$main::g\n";
