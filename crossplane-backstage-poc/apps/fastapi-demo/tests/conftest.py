def pytest_terminal_summary(terminalreporter, exitstatus, config):
    if exitstatus == 0:
        terminalreporter.write_sep("=", "TEST PASS")
