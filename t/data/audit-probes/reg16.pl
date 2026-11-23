our $g="a"; sub f { $g="b"; "x" } my $v = "$g@{[f()]}$g"; print "$v\n";
