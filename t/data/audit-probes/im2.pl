package P; use overload "+" => sub { 42 }; sub new { bless {}, shift } package main; my $o = P->new; print $o + 1, "\n";
