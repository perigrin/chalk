my @o; package D; sub new { bless {}, shift } sub DESTROY { push @o, "d" } package main; my $x = D->new; undef $x; print "@o\n";
