use warnings;
use strict;

sub next_token() {
	return undef unless $_;
	return &next_token if s/\A([\s(){}\[\]:)]|#.*)//;
	return 'i' . ${^MATCH} if s/\A[a-z_][a-z_\d]*//p;
	return 'n' . ${^MATCH} if s/\A\d+//p;
	return $3 ? 's' . $2 : die 'mising closing quote' if s/\A(["'])((?:(?!\1).)*)(\1|$)//;
	return 'c' . $1 if s/\A([A-Z])[A-Z]*//;
	return 'c' . ${^MATCH} if s/\A[-+*\/%^&|!`<>;=]//p;
	die "unknown token start '" . substr($_, 0, 1) . "'.";
}

sub tokenize($) {
	our ($_) = @_;

	my @tokens = ();
	push @tokens, &next_token while length $_;
	@tokens;
}

sub parse(@) {
	my $token = shift or die "attempted to parse an empty array";

	return [$token] if $token =~ /\A(?:[^c]|c[TFNP])/;
	return [$token, &parse] if $token =~ /\Ac[OEBC`!Q]/;
	return [$token, &parse, &parse] if $token =~ /\Ac[-+*\/%^&|!<>;=WR]/;
	return [$token, &parse, &parse, &parse] if $token eq 'cI';

	die "unknown token '$token'.";
}

sub run($);

sub to_bool($;$) {
	my $value = $_[1] ? $_[0]->[0] : &run($_[0])->[0];

	return 1 eq 'cT' if $value eq 'cT';
	return 0 if $value =~ /\Ac[NF]/;
	return $value ne 's' if 's' eq substr $value, 0, 1;
	return $value ne 'n0' if 'n' eq substr $value, 0, 1;

	die "unknown value '$value'";
}

sub to_string($;$) {
	my $value = $_[1] ? $_[0]->[0] : &run($_[0])->[0];

	return substr $value, 1 if substr($value, 0, 1) =~ /\A[sn]/;
	return 'NULL' if $value eq 'cN';
	return 'FALSE' if $value eq 'cF';
	return 'TRUE' if $value eq 'cT';

	die "unknown value '$value'";
}

sub to_num($;$) {
	my $value = $_[1] ? $_[0]->[0] : &run($_[0])->[0];
	return substr $value, 1 if substr($value, 0, 1) =~ /\A[sn]/;
	return '0' if $value =~ /\Ac[NF]/;
	return '1' if $value eq 'cT';

	die "unknown value '$value'";
}

sub run($) {
	our %env;
	%env = () unless %env;
	my ($cmd, $arg1, $arg2, $arg3) = @{$_[0]};
	my $ret;
	my $lhs;

	     if ('i' eq substr $cmd, 0, 1) { $env{substr($cmd, 1)};
	} elsif ($cmd =~ /\A([^c]|c[TFN])/) { [$cmd];
	} elsif ($cmd eq 'cP') { ['s' . <STDIN>];
	} elsif ($cmd eq 'cB') { $arg1;
	} elsif ($cmd eq 'cC') { &run(&run($arg1));
	} elsif ($cmd eq 'c`') { ['s' . `@{[to_string &run($arg1)->[0]]}`];
	} elsif ($cmd eq 'cQ') { exit to_num($arg1);
	} elsif ($cmd eq 'c!') { [to_bool($arg1) ? 'cF' : 'cT'];
	} elsif ($cmd eq 'cO') {
		$ret = &run($arg1);
		my $str = to_string($ret, 1);

		if ('\\' eq substr $str, -1) {
			print substr $str, length($str) - 1;
		} else {
			print $str, "\n";
		}
		[$ret];
	} elsif ($cmd eq 'cW') {
		$ret = ['cN'];
		$ret = &run($arg2) while to_bool($arg1);
		[$ret];
	} elsif ($cmd eq 'cR') { ['n' . (rand() * to_num($arg1) + to_run($arg2))];
	} elsif ($cmd eq 'c+') {
		if (($lhs = &run($arg1))->[0] =~ /\As/) {
			['s' . to_string($lhs, 1) . to_string($arg2)];
		} else {
			['n' . (to_num($lhs, 1) + to_num($arg2))];
		}
	} elsif ($cmd eq 'c-') { ['n' . (to_num($arg1) - to_num($arg2))];
	} elsif ($cmd eq 'c*') { ['n' . (to_num($arg1) * to_num($arg2))];
	} elsif ($cmd eq 'c/') { ['n' . (to_num($arg1) / to_num($arg2))];
	} elsif ($cmd eq 'c%') { ['n' . (to_num($arg1) % to_num($arg2))];
	} elsif ($cmd eq 'c^') { ['n' . (to_num($arg1) **to_num($arg2))];
	} elsif ($cmd eq 'c<') {
		if (($lhs = &run($arg1))->[0] =~ /\As/) {
			[(to_string($lhs, 1) lt to_string($arg2)) ? 'cT' : 'cF'];
		} else {
			[to_num($lhs, 1) < to_num($arg2) ? 'cT' : 'cF'];
		}
	} elsif ($cmd eq 'c>') {
		if (($lhs = &run($arg1))->[0] =~ /\As/) {
			[to_string($lhs, 1) gt to_string($arg2) ? 'cT' : 'cF'];
		} else {
			[to_num($lhs, 1) > to_num($arg2) ? 'cT' : 'cF'];
		}
	} elsif ($cmd eq 'c;') { &run($arg1); &run($arg2);
	} elsif ($cmd eq 'c&') { [to_bool($arg1) & to_bool($arg2) ? 'cT' : 'cF'];
	} elsif ($cmd eq 'c|') { [to_bool($arg1) | to_bool($arg2) ? 'cT' : 'cF'] ;
	} elsif ($cmd eq 'c=') { $env{substr($arg1->[0], 1)} = $lhs = &run($arg2); $lhs;
	} elsif ($cmd eq 'cI') { [&run(to_bool($arg1) ? $arg2 : $arg3)];
	} else { die "unknown command '$cmd'.";
	}
}

# ; n 1
# : WHILE < n 100
# 	; IF > 1 (% n 15)
# 		: OUTPUT "FizzBuzz"
# 	: IF > 1 (% n 3)
# 		: OUTPUT "Fizz"
# 	: IF > 1 (% n 5)
# 		: OUTPUT "Buzz" 
# 		# <ELSE>
# 		: OUTPUT n
	
# run parse tokenize <<EOS
# ; = fib BLOCK
# 	; = a 0
# 	; = b 1
# 	; WHILE n
# 		; = b + a = tmp b
# 		; = a tmp
# 		: = n - n 1
# 	: a
# ; = n 10
# ; OUTPUT +++ 'fib(' n ')=' CALL fib
# : O < 0 NULL
# EOS

run parse tokenize <<EOS

EOS
