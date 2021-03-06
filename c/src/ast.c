#include <ctype.h>  /* isspace, isdigit, islower, isupper */
#include <string.h> /* strdup */
#include <assert.h> /* assert */

#include "env.h"    /* kn_env_get */
#include "ast.h"    /* prototypes, kn_function_t, kn_value_t */
#include "shared.h" /* die, xmalloc, xrealloc */

/* get the first character of the stream. */
static char peek(const char **stream) {
	return **stream;
}

/* advance a single character in the stream. */
static void advance(const char **stream) {
	++(*stream);
}

/* advance a single character _and_ return the current one. */
static char next(const char **stream) {
	return *((*stream)++);
}

static void strip_stream(const char **stream) {
	char c;

	while (1) {
		c = peek(stream);

		switch (c) {
		case '#':
			// strip out comments
			do {
				c = next(stream);
			} while (c != '\0' && c != '\n');

			continue;

		case '(':
		case ')':
		case '[':
		case ']':
		case '{':
		case '}':
		case ':':
			// parens and colons are whitespace
			break;

		default:
			// whitespace is obviously whitespace ;p
			if (!isspace(c)) {
				return;
			}
		}

		advance(stream);
	}
}


static struct kn_ast_t kn_ast_parse_integer(const char **stream) {
	assert(isdigit(peek(stream)));

	kn_integer_t integer = 0;

	// This may possibly overflow `integer`, but meh. Part of Knight's spec
	// is that implementations may define the max integer literal.
	do {
		integer *= 10;
		integer += next(stream) - '0';
	} while (isdigit(peek(stream)));

	return (struct kn_ast_t) {
		.kind = KN_TT_VALUE,
		.value = kn_value_new_integer(integer)
	};
}

// identifiers are lower-case letters, numbers, and an underscore.
static int isident(char c) {
	return islower(c) || isdigit(c) || c == '_';
}

static struct kn_ast_t kn_ast_parse_identifier(const char **stream) {
	assert(isident(peek(stream)));

	// simply find the start and end of the identifier, then `strndup` it.
	const char *start = *stream;

	do {
		advance(stream);
	} while (isident(peek(stream)));

	char *identifier = strndup(start, *stream - start);

	return (struct kn_ast_t) {
		.kind = KN_TT_IDENTIFIER,
		.identifier = identifier
	};
}

static struct kn_ast_t kn_ast_parse_string(const char **stream) {
	char quote = peek(stream);

	assert(quote == '\"' || quote == '\'');

	advance(stream); // delete the starting quote before setting `start`.
	const char *start = *stream;
	char c;

	do {
		c = peek(stream);

		if (c == '\0') {
			die("unterminated quote encountered: '%s'", start);
		}

		advance(stream);
	} while (c != quote);

	// subtract one because we've already advanced the ending quote.
	char *string = strndup(start, *stream - start - 1);

	return (struct kn_ast_t) {
		.kind = KN_TT_VALUE,
		.value = kn_value_new_string(kn_string_new(string))
	};
}


static struct kn_ast_t kn_ast_parse_function(const char **stream) {
	char name = next(stream);

	// strip trailing function words, if we're a non-symbolic function.
	if (isupper(name)) {
		do {
			advance(stream);
		} while (isupper(peek(stream)));
	}

	const struct kn_function_t *function = kn_fn_fetch(name);

	if (function == NULL) {
		die("unknown function '%c' encountered.", name);
	}

	size_t arity = function->arity;

	struct kn_ast_t ast = (struct kn_ast_t) {
		.kind = KN_TT_FUNCTION,
		.function = function,
		.arguments = xmalloc(arity * sizeof(struct kn_ast_t))
	};

	for (size_t i = 0; i < arity; ++i) {
		ast.arguments[i] = kn_ast_parse(stream);
	}

	return ast;
}

struct kn_ast_t kn_ast_parse(const char **stream) {
	strip_stream(stream);
	char peeked = peek(stream);

	// OPTIMIZATION: In the future, this could probably be optimized by
	// having a massive switch statement for every possible character. (this
	// is what I do in the assembly approach.)

	if (isdigit(peeked)) {
		return kn_ast_parse_integer(stream);
	}

	if (isident(peeked)) {
		return kn_ast_parse_identifier(stream);
	}

	if (peeked == '\'' || peeked == '"') {
		return kn_ast_parse_string(stream);
	}

	if (isupper(peeked) || ispunct(peeked)) {
		return kn_ast_parse_function(stream);
	}

	if (peeked == '\0') {
		die("unexpected eof; expected an expression.");
	} else {
		die("unknown token start '%c'", peeked);
	}
}

struct kn_value_t kn_ast_run(const struct kn_ast_t *ast) {
	switch (ast->kind) {
	case KN_TT_VALUE:
		return kn_value_clone(&ast->value);

	case KN_TT_IDENTIFIER: {
		const struct kn_value_t *retptr = kn_env_get(ast->identifier);

		if (retptr == NULL) {
			die("unknown identifier '%s'", ast->identifier);
		}

		return kn_value_clone(retptr);
	}

	case KN_TT_FUNCTION:
		return (ast->function->func)(ast->arguments);

	default:
		bug("unknown kind '%d'");
	}
}

struct kn_ast_t kn_ast_clone(const struct kn_ast_t *ast) {
	struct kn_ast_t ret = (struct kn_ast_t) {
		.kind = ast->kind
	};

	switch (ret.kind) {
	case KN_TT_VALUE:
		ret.value = kn_value_clone(&ast->value);
		return ret;

	case KN_TT_IDENTIFIER: {
		ret.identifier = strdup((char *) ast->identifier);

		if (ret.identifier == NULL) {
			die("unable to duplicate identifier");
		}

		return ret;
	}

	case KN_TT_FUNCTION: {
		ret.function = ast->function;
		size_t arity = ret.function->arity;

		ret.arguments = xmalloc(arity * sizeof(struct kn_ast_t));

		for (size_t i = 0; i < arity; i++) {
			ret.arguments[i] = kn_ast_clone(&ast->arguments[i]);
		}

		return ret;
	}

	default:
		bug("unknown kind '%d'", ast->kind);
	}
}

void kn_ast_free(struct kn_ast_t *ast) {
	switch (ast->kind) {
	case KN_TT_VALUE:
		kn_value_free(&ast->value);
		break;

	case KN_TT_IDENTIFIER:
		free((void *) ast->identifier);
		break;

	case KN_TT_FUNCTION:
		for (size_t i = 0; i < ast->function->arity; ++i) {
			kn_ast_free(&ast->arguments[i]);
		}

		free((void *) ast->arguments);
		break;

	default:
		bug("unknown kind '%d'", ast->kind);
	}
}
