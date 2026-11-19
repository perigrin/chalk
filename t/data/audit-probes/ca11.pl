package A; sub new { bless {}, shift } sub hi { "A" } package B; our @ISA = ("A"); sub hi { my $s = shift; "B" . $s->SUPER::hi() } package main; print B->new->hi, "\n";
