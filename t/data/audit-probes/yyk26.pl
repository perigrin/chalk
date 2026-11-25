package P; sub new { bless {}, shift } sub AUTOLOAD { our $AUTOLOAD; my $n = $AUTOLOAD; $n =~ s/.*:://; return if $n eq "DESTROY"; "auto($n)" } package main; print P->new->foo, P->bar(1), "\n";
