package A; sub new { bless [], shift } package B; our @ISA=('A'); package main; my $o=B->new; print ref($o), $o->isa('A')?1:0, UNIVERSAL::isa($o,'ARRAY')?1:0, "\n";
