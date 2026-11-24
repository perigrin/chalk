package D; our $n=0; sub new { bless {}, shift } sub DESTROY { $n++ } package main; { my $o=D->new; } print "$D::n\n";
