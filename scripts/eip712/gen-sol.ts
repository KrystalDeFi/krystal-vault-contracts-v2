// @ts-nocheck
const { keccak256 } = require('viem');
const x = require('./order');

function isAtomic(t) {
  return t.startsWith('bytes') || t.startsWith('uint') || t.startsWith('int') || t === 'bool' || t === 'address';
}

const objs = {}
Object.keys(x).forEach(key => {
  objs[key] = {
    arr: x[key],
    objName: key,
    deps: [],
  };
});

function getDeps(obj, deps = []) {
  obj.arr.forEach(element => {
    if (objs[element.type]) {
      if (!deps.includes(element.type)) {
        deps.push(element.type);
        getDeps(objs[element.type], deps);
      }
    }
  });
  deps.sort();
  return deps;
}

function getInitHashString(obj) {
  let fieldList = [];
  obj.arr.forEach(element => {
    fieldList.push(`${element.type} ${element.name}`);
  });
  let fields = fieldList.join(',');
  let hashString = `${obj.objName}(${fields})`;
  return hashString;
}

function getFullHashString(obj) {
  let hashString = getInitHashString(obj);
  obj.deps.forEach(dep => {
    hashString += getInitHashString(objs[dep]);
  }); 
  return hashString;
}

function genTypeHashStatement(obj) {
  return `    // keccak256(
    //     \"${getFullHashString(obj)}\"
    // );
    bytes32 constant ${obj.objName}_TYPEHASH = ${keccak256(getFullHashString(obj))};` // do NOT delete spaces
}

function genStruct(obj) {
  let fieldList = [];
  obj.arr.forEach(element => {
    let ename = element.name;
    if (element.name === 'type') {
      ename = '_type';
    }
    fieldList.push(`        ${element.type} ${ename};\n`);
  });
  return `    struct ${obj.objName} {\n${fieldList.join('')}    }` // do NOT delete spaces
}

function genHashFunction(obj) {
  let fieldList = [`${obj.objName}_TYPEHASH`];
  obj.arr.forEach(element => {
    let ename = element.name;
    if (element.name === 'type') {
      ename = '_type';
    }
  let hashLine;
	if (isAtomic(element.type)) {
		hashLine = `obj.${ename}`;
	} else if (element.type === 'string') {
		hashLine = `keccak256(bytes(obj.${ename}))`;
	} else if (element.type === 'bytes') {
		hashLine = `keccak256(obj.${ename})`;
	} else {
		hashLine = `_hash(obj.${ename})`;
	}
	fieldList.push(hashLine);
  });
  let functionString = `    function _hash(${obj.objName} memory obj) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            ${fieldList.join(',\n            ')}
        ));
    }`
  return functionString;
}

Object.keys(objs).forEach(key => {
  objs[key].deps = getDeps(objs[key]);
});

Object.keys(objs).forEach(key => {
  const obj = objs[key];
  console.log(genTypeHashStatement(obj));
  console.log(genStruct(obj));
  console.log(genHashFunction(obj));
  console.log();
});