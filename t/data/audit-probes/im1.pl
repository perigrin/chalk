package P; use overload q("") => sub { "P!" }; sub new { bless {}, shift } package main; my $o = P->new; print "$o\n";
