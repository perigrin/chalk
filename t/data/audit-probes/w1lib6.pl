use v5.38; use feature 'class'; no warnings; class C { field $x = 1; ADJUST { $main::g += 10 } } my $x = $main::g; for my $i (1..3) { print "$main::g\n"; C->new; } print "$main::g\n";
