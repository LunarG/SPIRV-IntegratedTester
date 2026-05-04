#include <fstream>
#include <iostream>
#include <sstream>
#include <string>

#include "effcee/effcee.h"

static bool read_file(const std::string& path, std::string& contents) {
    std::ifstream file(path);
    if (!file.is_open()) {
        std::cerr << "error: cannot open file '" << path << "'\n";
        return false;
    }
    std::ostringstream ss;
    ss << file.rdbuf();
    contents = ss.str();
    return true;
}

int main(int argc, char* argv[]) {
    std::string spvasm_path;
    std::string source_path;

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--spvasm" && i + 1 < argc) {
            spvasm_path = argv[++i];
        } else if (arg == "--source" && i + 1 < argc) {
            source_path = argv[++i];
        } else {
            std::cerr << "error: unknown argument '" << arg << "'\n";
            return 1;
        }
    }

    if (spvasm_path.empty() || source_path.empty()) {
        std::cerr << "usage: FileCheck --spvasm <input.spvasm> --source <source.slang>\n";
        return 1;
    }

    std::string spvasm_contents;
    std::string source_contents;

    if (!read_file(spvasm_path, spvasm_contents)) return 1;
    if (!read_file(source_path, source_contents)) return 1;

    auto result = effcee::Match(spvasm_contents, source_contents,
                                effcee::Options().SetChecksName(source_path).SetInputName(spvasm_path));

    if (result) {
        return 0;
    }

    switch (result.status()) {
        case effcee::Result::Status::NoRules:
            std::cerr << "error: no CHECK rules found in '" << source_path << "'\n";
            break;
        case effcee::Result::Status::Fail:
            std::cerr << result.message() << "\n";
            break;
        default:
            break;
    }
    return 1;
}
