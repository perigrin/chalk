package A; our $AUTOLOAD; sub new { bless {}, shift } sub AUTOLOAD { my $n = $AUTOLOAD; $n =~ s/.*:://; return if $n eq "DESTROY"; return "auto:$n" } package main; print A->new->foo, "\n";
