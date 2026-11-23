sub new { my ($c,%a)=@_; my %s=%a; $s{x}=1; print join(",",sort keys %a),"\n" } new("C", y=>2);
