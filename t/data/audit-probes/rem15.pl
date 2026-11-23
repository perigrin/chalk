sub mod { my %o=@_; $o{a}=9; %o } my %a=(a=>1); my %b=mod(%a); print "$a{a}$b{a}\n";
