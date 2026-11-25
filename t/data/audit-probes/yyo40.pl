use overload; use vars qw($v @l); $v = 1; @l = (1,2); print "$v@l", defined &overload::StrVal ? "sv" : "no", "\n";
