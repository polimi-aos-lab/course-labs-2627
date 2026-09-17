"""Load Linux kernel module symbols at their runtime section addresses."""

import os

import gdb


class _ModuleLoadBreakpoint(gdb.Breakpoint):
    def __init__(self, command):
        super().__init__("do_init_module", internal=True)
        self.command = command
        self.silent = True

    def stop(self):
        return self.command.load_current_module()


class AOSModuleSymbols(gdb.Command):
    """Arrange runtime symbol loading for the next module passed to insmod.

Usage: aos-module-symbols PATH
PATH is either the module.ko file or its containing directory.
Set source breakpoints after running this command, then continue and insmod.
"""

    def __init__(self):
        super().__init__("aos-module-symbols", gdb.COMMAND_FILES)
        self.breakpoint = None
        self.module_file = None
        self.loaded_text_address = None

    @staticmethod
    def _resolve_module_file(path):
        path = os.path.abspath(os.path.expanduser(path))
        if os.path.isfile(path):
            return path

        candidate = os.path.join(path, "module.ko")
        if os.path.isfile(candidate):
            return candidate

        raise gdb.GdbError("no module.ko found at '{}'".format(path))

    @staticmethod
    def _runtime_sections(module):
        try:
            section_attributes = module["sect_attrs"].dereference()
        except gdb.error as error:
            raise gdb.GdbError(
                "kernel module section addresses are unavailable: {}".format(error)
            )

        attributes = section_attributes["attrs"]
        sections = {}
        for index in range(int(section_attributes["nsections"])):
            attribute = attributes[index]
            name = attribute["battr"]["attr"]["name"].string()
            address = int(attribute["address"])
            if address:
                sections[name] = address
        return sections

    def load_current_module(self):
        try:
            module = gdb.parse_and_eval("mod")
            module_name = module["name"].string()
            sections = self._runtime_sections(module)
            text_address = sections.get(".text")
            if text_address is None:
                text_address = int(module["core_layout"]["base"])

            if self.loaded_text_address is not None:
                try:
                    gdb.execute(
                        "remove-symbol-file -a {:#x}".format(
                            self.loaded_text_address
                        ),
                        to_string=True,
                    )
                except gdb.error:
                    pass

            escaped_file = self.module_file.replace("\\", "\\\\").replace(
                '"', '\\"'
            )
            arguments = [
                'add-symbol-file "{}" {:#x}'.format(
                    escaped_file, text_address
                )
            ]
            for name, address in sorted(sections.items()):
                if name != ".text":
                    arguments.append("-s {} {:#x}".format(name, address))

            gdb.execute(" ".join(arguments))
            self.loaded_text_address = text_address
            gdb.write(
                "AOS: loaded symbols for '{}' from {}\n".format(
                    module_name, self.module_file
                )
            )
            return False
        except (gdb.error, gdb.GdbError, KeyError, TypeError, ValueError) as error:
            gdb.write("AOS: module symbol loading failed: {}\n".format(error))
            return True

    def invoke(self, argument, from_tty):
        arguments = gdb.string_to_argv(argument)
        if len(arguments) != 1:
            raise gdb.GdbError("usage: aos-module-symbols PATH")

        self.module_file = self._resolve_module_file(arguments[0])
        if self.breakpoint is not None:
            self.breakpoint.delete()
        self.breakpoint = _ModuleLoadBreakpoint(self)
        gdb.execute("set breakpoint pending on")
        gdb.write(
            "AOS: will load {} when insmod reaches do_init_module\n".format(
                self.module_file
            )
        )


AOSModuleSymbols()
