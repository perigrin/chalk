package C; my $count = 0; sub new { $count++; bless {}, shift } sub count { $count } package main; C->new for 1..3; print C->count, C::count(), "\n";
