package P; use overload "==" => sub { 1 }, "bool" => sub { 0 }; sub new { bless {}, shift } package main; my $o = P->new; print(($o ? "t" : "f"), "\n");
