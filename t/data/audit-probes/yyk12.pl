package G; sub new { my ($c,$f)=@_; bless {f=>$f}, $c } sub DESTROY { $_[0]{f}->() } package main; my $n=0; { my $g = G->new(sub { $n++ }); } print "$n\n";
