var fs = require('fs')
const header = `const Order = {
`
const footer = `}

module.exports = Order;
`

let orderFileContent = header;
var lineReader = require('readline').createInterface({
    input: fs.createReadStream('scripts/eip712/order.txt')
});

lineReader.on('line', function (line: string) {
    line = line.replace(' = []apitypes.Type{', ': [');
    line = line.replace('Name:', 'name:');
    line = line.replace('Type:', 'type:');
    if (line == '}') {
        line = '],';
    }
    orderFileContent += `    ${line}\n`;
});

lineReader.on('close', function () {
    orderFileContent += footer;
    fs.createWriteStream('scripts/eip712/order.ts').write(orderFileContent);
    console.log('all done!!!');
});

