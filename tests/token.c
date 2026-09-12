#include <stdarg.h>
#include <stdio.h>

#include "ntstatus.h"
#define WIN32_NO_STATUS
#include "windef.h"
#include "winbase.h"
#include "winternl.h"
#include "wine/test.h"

static void test_query_token_info(void)
{
    TOKEN_STATISTICS stats;
    NTSTATUS status;
    HANDLE token;
    ULONG len;
    ULONG retlen;

    status = NtOpenProcessToken( GetCurrentProcess(), TOKEN_QUERY, &token );
    ok( !status, "NtOpenProcessToken failed %lx\n", status );

    // Known class in info_len with bad length, must fail
    retlen = 42;
    len = 0;
    status = NtQueryInformationToken( token, TokenStatistics, NULL, len, &retlen );
    ok( status == STATUS_BUFFER_TOO_SMALL, "got %lx\n", status );
    ok( retlen == sizeof(TOKEN_STATISTICS), "got %lu\n", retlen );

    // Known class in info_len with correct length, must succeed
    retlen = 42;
    len = sizeof(TOKEN_STATISTICS);
    status = NtQueryInformationToken( token, TokenStatistics, &stats, len, &retlen );
    ok( !status, "got %lx\n", status );
    ok( retlen == sizeof(TOKEN_STATISTICS), "got %lu\n", retlen );


    // Class not in info_len with correct length, undefined behaviour
    retlen = 42;
    len = 0;
    status = NtQueryInformationToken( token, TokenIsAppSilo, NULL, len, &retlen );
    ok( status == STATUS_NOT_IMPLEMENTED, "got %lx\n", status );
    ok( retlen == len, "got %lu\n", retlen );

    NtClose( token );
}

START_TEST(token)
{
    test_query_token_info();
}
