package C; my $cnt=0; sub new { $cnt++; bless {}, shift } sub count { $cnt } package main; C->new; C->new; print C->count,"\n";
